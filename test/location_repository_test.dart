import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/location_repository.dart';
import 'package:geo_groups/supabase_bootstrap.dart';

void main() {
  test('a locations row becomes a member location', () {
    final locations = mapLocationRows([
      {
        'group_id': 'group-1',
        'user_id': 'user-1',
        'latitude': 55.751244,
        'longitude': 37.618423,
        'updated_at': '2026-11-20T14:05:00.000Z',
      },
    ]);

    expect(locations, hasLength(1));
    expect(locations.single.memberId, 'user-1');
    expect(locations.single.coordinate.latitude, 55.751244);
    expect(locations.single.coordinate.longitude, 37.618423);
    expect(
      locations.single.updatedAt,
      DateTime.parse('2026-11-20T14:05:00.000Z'),
    );
  });

  test('an empty locations response stays empty', () {
    expect(mapLocationRows(const []), isEmpty);
  });

  test('the local repository does not touch the network', () async {
    final repository = LocalLocationRepository();
    final coordinate = GeoCoordinate(latitude: 55.75, longitude: 37.62);

    expect(await repository.loadGroupLocations('group-1'), isEmpty);
    await repository.upsertMyLocation(
      groupId: 'group-1',
      userId: 'user-1',
      coordinate: coordinate,
    );
  });

  test(
    'upsert sends the schema coordinate columns and no client time',
    () async {
      final captured = <Map<String, dynamic>>[];
      final repository = SupabaseLocationRepository(
        locations: (_) async => const [],
        upsert: (row) async {
          captured.add(row);
        },
      );
      final coordinate = GeoCoordinate(
        latitude: 59.939095,
        longitude: 30.315868,
      );

      await repository.upsertMyLocation(
        groupId: 'group-7',
        userId: 'user-7',
        coordinate: coordinate,
      );

      expect(captured, hasLength(1));
      expect(captured.single, {
        'group_id': 'group-7',
        'user_id': 'user-7',
        'latitude': 59.939095,
        'longitude': 30.315868,
      });
      expect(captured.single.containsKey('updated_at'), isFalse);
    },
  );

  test('repository choice follows the startup mode', () {
    expect(
      locationRepositoryFor(SupabaseStartup.local),
      isA<LocalLocationRepository>(),
    );
    expect(
      locationRepositoryFor(SupabaseStartup.failed),
      isA<LocalLocationRepository>(),
    );
    expect(
      locationRepositoryFor(SupabaseStartup.ready),
      isA<SupabaseLocationRepository>(),
    );
  });

  test('load uses injected rows and does not call upsert', () async {
    var upserts = 0;
    final repository = SupabaseLocationRepository(
      locations: (groupId) async {
        expect(groupId, 'group-1');
        return [
          {
            'user_id': 'user-2',
            'latitude': 1,
            'longitude': 2,
            'updated_at': '2026-11-20T15:00:00Z',
          },
        ];
      },
      upsert: (_) async {
        upserts += 1;
      },
    );

    final locations = await repository.loadGroupLocations('group-1');

    expect(upserts, 0);
    expect(locations.single.memberId, 'user-2');
    expect(locations.single.coordinate.latitude, 1);
    expect(locations.single.coordinate.longitude, 2);
    expect(locations.single.updatedAt, DateTime.parse('2026-11-20T15:00:00Z'));
  });
}
