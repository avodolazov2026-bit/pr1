import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_map_screen.dart';

import 'fake_location_device.dart';

void main() {
  GeoGroup group({
    required String id,
    required String name,
    required DateTime startsAt,
    DateTime? endsAt,
  }) {
    return GeoGroup(
      id: id,
      name: name,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      startsAt: startsAt,
      endsAt: endsAt,
      members: const [],
    );
  }

  testWidgets('an active group shows a marker for each active member', (
    tester,
  ) async {
    final now = DateTime.now();
    final active = GeoGroup(
      id: 'map-active',
      name: 'Прогулка',
      createdAt: now.subtract(const Duration(days: 1)),
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      members: [
        GroupMember(id: 'maria', name: 'Мария'),
        GroupMember(
          id: 'olga',
          name: 'Ольга',
          status: MembershipStatus.invited,
        ),
        GroupMember(id: 'alexey', name: 'Алексей'),
      ],
      memberLocations: [
        GroupMemberLocation(
          memberId: 'maria',
          coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
          updatedAt: now,
        ),
        GroupMemberLocation(
          memberId: 'olga',
          coordinate: GeoCoordinate(latitude: 55.7601, longitude: 37.6186),
          updatedAt: now,
        ),
        GroupMemberLocation(
          memberId: 'alexey',
          coordinate: GeoCoordinate(latitude: 55.749, longitude: 37.605),
          updatedAt: now,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(locationProvider: _silentLocation, group: active),
      ),
    );
    await tester.pump();

    expect(find.text('Карта группы'), findsOneWidget);
    expect(find.text('Группа: «Прогулка»'), findsOneWidget);
    expect(find.text('Тестовая точка на карте'), findsNothing);
    expect(find.text('OpenStreetMap contributors'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsNWidgets(2));
    expect(_positionLabel('Мария'), findsOneWidget);
    expect(_positionLabel('Алексей'), findsOneWidget);
    expect(_positionLabel('Ольга'), findsNothing);
    expect(find.byTooltip('Мария'), findsOneWidget);
    expect(find.byTooltip('Ольга'), findsNothing);
    expect(find.text('На карте: 2 участника'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsNothing);
  });

  testWidgets('tap on a marker shows the member and the update time', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _twoActiveMembers(now),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();

    expect(find.text('Мария'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsOneWidget);
    expect(find.text('Алексей'), findsNothing);
    expect(find.text('На карте: 2 участника'), findsNothing);
  });

  testWidgets('tap on the same marker again hides the details', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _twoActiveMembers(now),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();
    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();

    expect(find.textContaining('Обновлено:'), findsNothing);
    expect(find.text('На карте: 2 участника'), findsOneWidget);
  });

  testWidgets('tap on empty map hides the member details', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _twoActiveMembers(now),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();
    expect(find.textContaining('Обновлено:'), findsOneWidget);

    final mapBox = tester.getRect(find.byType(FlutterMap));
    await tester.tapAt(mapBox.topLeft + const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Обновлено:'), findsNothing);
    expect(find.text('На карте: 2 участника'), findsOneWidget);
  });

  testWidgets(
    'a removed position clears the selection and does not restore it',
    (tester) async {
      final now = DateTime.now();
      GeoGroup withMaria({required bool located}) {
        return GeoGroup(
          id: 'map-maria',
          name: 'Прогулка',
          createdAt: now.subtract(const Duration(days: 1)),
          startsAt: now.subtract(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 2)),
          members: [GroupMember(id: 'maria', name: 'Мария')],
          memberLocations: located
              ? [
                  GroupMemberLocation(
                    memberId: 'maria',
                    coordinate: GeoCoordinate(
                      latitude: 55.7558,
                      longitude: 37.6173,
                    ),
                    updatedAt: now.subtract(const Duration(minutes: 5)),
                  ),
                ]
              : const [],
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: GroupMapScreen(
            locationProvider: _silentLocation,
            group: withMaria(located: true),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Мария'));
      await tester.pump();
      expect(find.textContaining('Обновлено:'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupMapScreen(
            locationProvider: _silentLocation,
            group: withMaria(located: false),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Обновлено:'), findsNothing);
      expect(find.text('Нет актуальных позиций участников'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupMapScreen(
            locationProvider: _silentLocation,
            group: withMaria(located: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Обновлено:'), findsNothing);
      expect(find.text('На карте: 1 участник'), findsOneWidget);
    },
  );

  testWidgets('an active group without locations shows an empty map', (
    tester,
  ) async {
    final now = DateTime.now();
    final active = GeoGroup(
      id: 'map-empty',
      name: 'Без позиций',
      createdAt: now.subtract(const Duration(days: 1)),
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      members: [GroupMember(id: 'maria', name: 'Мария')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(locationProvider: _silentLocation, group: active),
      ),
    );
    await tester.pump();

    expect(find.byType(FlutterMap), findsOneWidget);
    final emptyOptions = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .options;
    expect(emptyOptions.initialCenter, const LatLng(0, 0));
    expect(emptyOptions.initialZoom, 2);
    expect(emptyOptions.initialCameraFit, isNull);
    expect(find.byIcon(Icons.location_on), findsNothing);
    expect(find.text('Нет актуальных позиций участников'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one visible position centers the map on that member', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: GeoGroup(
            id: 'map-one',
            name: 'Одна точка',
            createdAt: now.subtract(const Duration(days: 1)),
            startsAt: now.subtract(const Duration(hours: 1)),
            endsAt: now.add(const Duration(hours: 2)),
            members: [GroupMember(id: 'maria', name: 'Мария')],
            memberLocations: [
              GroupMemberLocation(
                memberId: 'maria',
                coordinate: GeoCoordinate(
                  latitude: 55.7558,
                  longitude: 37.6173,
                ),
                updatedAt: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(options.initialCenter, const LatLng(55.7558, 37.6173));
    expect(options.initialZoom, 13);
    expect(options.initialCameraFit, isNull);
  });

  testWidgets('two distant positions fit inside the initial camera bounds', (
    tester,
  ) async {
    final now = DateTime.now();
    const moscow = LatLng(55.7558, 37.6173);
    const vladivostok = LatLng(43.1155, 131.8855);
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: GeoGroup(
            id: 'map-bounds',
            name: 'Две точки',
            createdAt: now.subtract(const Duration(days: 1)),
            startsAt: now.subtract(const Duration(hours: 1)),
            endsAt: now.add(const Duration(hours: 2)),
            members: [
              GroupMember(id: 'maria', name: 'Мария'),
              GroupMember(id: 'alexey', name: 'Алексей'),
            ],
            memberLocations: [
              GroupMemberLocation(
                memberId: 'maria',
                coordinate: GeoCoordinate(
                  latitude: moscow.latitude,
                  longitude: moscow.longitude,
                ),
                updatedAt: now,
              ),
              GroupMemberLocation(
                memberId: 'alexey',
                coordinate: GeoCoordinate(
                  latitude: vladivostok.latitude,
                  longitude: vladivostok.longitude,
                ),
                updatedAt: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final fit = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .options
        .initialCameraFit;
    expect(fit, isA<FitBounds>());
    final boundsFit = fit! as FitBounds;
    expect(boundsFit.padding, const EdgeInsets.all(48));
    expect(boundsFit.bounds.contains(moscow), isTrue);
    expect(boundsFit.bounds.contains(vladivostok), isTrue);
  });

  testWidgets('two active members show the fit-all button', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _twoActiveMembers(now),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Показать всех участников'), findsOneWidget);
    expect(find.byIcon(Icons.fit_screen), findsOneWidget);
  });

  testWidgets('an empty map hides the fit-all button', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: GeoGroup(
            id: 'map-empty-button',
            name: 'Без позиций',
            createdAt: now.subtract(const Duration(days: 1)),
            startsAt: now.subtract(const Duration(hours: 1)),
            endsAt: now.add(const Duration(hours: 2)),
            members: [GroupMember(id: 'maria', name: 'Мария')],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Показать всех участников'), findsNothing);
    expect(find.byIcon(Icons.fit_screen), findsNothing);
  });

  testWidgets('fitting all members keeps the selected member card', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _twoActiveMembers(now),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();
    await tester.tap(find.byTooltip('Показать всех участников'));
    await tester.pump();

    expect(find.text('Мария'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsOneWidget);
    expect(find.text('На карте: 2 участника'), findsNothing);
  });

  testWidgets('fitting all members does not throw', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _twoActiveMembers(now),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Показать всех участников'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('organizer and participant markers use different labels', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _organizerAndParticipant(now),
        ),
      ),
    );
    await tester.pump();

    expect(_semantics('Позиция организатора: Мария'), findsOneWidget);
    expect(_semantics('Позиция участника: Алексей'), findsOneWidget);
    expect(_semantics('Позиция организатора: Алексей'), findsNothing);
    expect(
      find.descendant(
        of: _semantics('Позиция организатора: Мария'),
        matching: find.byIcon(Icons.star),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _semantics('Позиция участника: Алексей'),
        matching: find.byIcon(Icons.star),
      ),
      findsNothing,
    );
    expect(_pin(tester, 'Позиция организатора: Мария').color, Colors.purple);
    expect(_pin(tester, 'Позиция участника: Алексей').color, Colors.blue);
  });

  testWidgets('current user who organizes the group has one marker', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _currentUserOrganizer(now),
        ),
      ),
    );
    await tester.pump();

    expect(_semantics('Ваше местоположение, организатор'), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsNWidgets(2));
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label ?? '').startsWith('Позиция организатора:'),
      ),
      findsNothing,
    );
    final pin = _pin(tester, 'Ваше местоположение, организатор');
    expect(pin.color, const Color(0xFF00897B));
    expect(_hasWhiteOutline(pin), isTrue);
  });

  testWidgets('selecting the organizer keeps the organizer marker', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _organizerAndParticipant(now),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();

    expect(find.text('Мария'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsOneWidget);
    expect(_semantics('Позиция организатора: Мария'), findsOneWidget);
    expect(
      find.descendant(
        of: _semantics('Позиция организатора: Мария'),
        matching: find.byIcon(Icons.star),
      ),
      findsOneWidget,
    );
    final pin = _pin(tester, 'Позиция организатора: Мария');
    expect(pin.color, Colors.purple);
    expect(pin.size, 56);
    expect(pin.shadows?.any((shadow) => shadow.blurRadius > 0), isTrue);
    expect(_hasWhiteOutline(pin), isTrue);
    expect(_pin(tester, 'Позиция участника: Алексей').color, Colors.blue);
    expect(_pin(tester, 'Позиция участника: Алексей').size, 44);
  });

  testWidgets('coincident positions keep only the current user marker', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _samePoint(
            id: 'map-same-self',
            now: now,
            members: [
              GroupMember(id: currentDemoUserId, name: 'Вы'),
              GroupMember(
                id: 'maria',
                name: 'Мария',
                role: MemberRole.organizer,
              ),
              GroupMember(id: 'alexey', name: 'Алексей'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.location_on), findsOneWidget);
    expect(_semantics('Ваше местоположение'), findsOneWidget);
    expect(_semantics('Позиция организатора: Мария'), findsNothing);
    expect(_semantics('Позиция участника: Алексей'), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('coincident organizer and participant keep the organizer', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: _samePoint(
            id: 'map-same-organizer',
            now: now,
            members: [
              GroupMember(
                id: 'maria',
                name: 'Мария',
                role: MemberRole.organizer,
              ),
              GroupMember(id: 'alexey', name: 'Алексей'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.location_on), findsOneWidget);
    expect(_semantics('Позиция организатора: Мария'), findsOneWidget);
    expect(_semantics('Позиция участника: Алексей'), findsNothing);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(_pin(tester, 'Позиция организатора: Мария').color, Colors.purple);
  });

  testWidgets('current user who is not the organizer keeps their own marker', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: _silentLocation,
          group: GeoGroup(
            id: 'map-self',
            name: 'Своя точка',
            createdAt: now.subtract(const Duration(days: 1)),
            startsAt: now.subtract(const Duration(hours: 1)),
            endsAt: now.add(const Duration(hours: 2)),
            members: [GroupMember(id: currentDemoUserId, name: 'Вы')],
            memberLocations: [
              GroupMemberLocation(
                memberId: currentDemoUserId,
                coordinate: GeoCoordinate(
                  latitude: 55.7539,
                  longitude: 37.6208,
                ),
                updatedAt: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_semantics('Ваше местоположение'), findsOneWidget);
    expect(_semantics('Ваше местоположение, организатор'), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
    final pin = _pin(tester, 'Ваше местоположение');
    expect(pin.color, const Color(0xFF00897B));
    expect(_hasWhiteOutline(pin), isTrue);
  });

  testWidgets('a device position shows the current user marker', (
    tester,
  ) async {
    final now = DateTime.now();
    final device = FakeLocationDevice(
      permission: LocationAccess.granted,
      position: GeoCoordinate(latitude: 55.7539, longitude: 37.6208),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: DeviceLocationProvider(device: device),
          group: _locatedGroup(
            id: 'map-device',
            now: now,
            members: [
              GroupMember(id: currentDemoUserId, name: 'Вы'),
              GroupMember(id: 'maria', name: 'Мария'),
            ],
            locations: [
              GroupMemberLocation(
                memberId: 'maria',
                coordinate: GeoCoordinate(
                  latitude: 55.7558,
                  longitude: 37.6173,
                ),
                updatedAt: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(device.requests, 0);
    expect(_semantics('Ваше местоположение'), findsOneWidget);
    expect(_semantics('Позиция участника: Мария'), findsOneWidget);
    final pin = _pin(tester, 'Ваше местоположение');
    expect(pin.color, const Color(0xFF00897B));
    expect(_hasWhiteOutline(pin), isTrue);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(
      _markerPoint(tester, 'Ваше местоположение'),
      const LatLng(55.7539, 37.6208),
    );
  });

  testWidgets('a missing device position keeps the other markers', (
    tester,
  ) async {
    final now = DateTime.now();
    final cases = [
      FakeLocationDevice(servicesEnabled: false),
      FakeLocationDevice(permission: LocationAccess.denied),
      FakeLocationDevice(permission: LocationAccess.deniedForever),
      FakeLocationDevice(
        permission: LocationAccess.granted,
        readError: StateError('gps'),
      ),
    ];
    for (var index = 0; index < cases.length; index++) {
      final device = cases[index];
      await tester.pumpWidget(
        MaterialApp(
          home: GroupMapScreen(
            locationProvider: DeviceLocationProvider(device: device),
            group: _locatedGroup(
              id: 'map-device-fail-$index',
              now: now,
              members: [
                GroupMember(id: currentDemoUserId, name: 'Вы'),
                GroupMember(id: 'maria', name: 'Мария'),
              ],
              locations: [
                GroupMemberLocation(
                  memberId: 'maria',
                  coordinate: GeoCoordinate(
                    latitude: 55.7558,
                    longitude: 37.6173,
                  ),
                  updatedAt: now,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(device.requests, 0);
      expect(_semantics('Ваше местоположение'), findsNothing);
      expect(_semantics('Позиция участника: Мария'), findsOneWidget);
      expect(find.text('На карте: 1 участник'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a failed device read leaves an empty map usable', (
    tester,
  ) async {
    final now = DateTime.now();
    final device = FakeLocationDevice(
      permission: LocationAccess.granted,
      readError: StateError('gps'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: DeviceLocationProvider(device: device),
          group: _locatedGroup(
            id: 'map-device-empty',
            now: now,
            members: [GroupMember(id: currentDemoUserId, name: 'Вы')],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(device.requests, 0);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(_semantics('Ваше местоположение'), findsNothing);
    expect(find.text('Нет актуальных позиций участников'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fresh device position replaces the stored user point', (
    tester,
  ) async {
    final now = DateTime.now();
    final stored = GeoCoordinate(latitude: 55.7, longitude: 37.6);
    final group = _locatedGroup(
      id: 'map-device-replace',
      now: now,
      members: [
        GroupMember(id: currentDemoUserId, name: 'Вы'),
        GroupMember(id: 'maria', name: 'Мария'),
      ],
      locations: [
        GroupMemberLocation(
          memberId: currentDemoUserId,
          coordinate: stored,
          updatedAt: now.subtract(const Duration(minutes: 30)),
        ),
        GroupMemberLocation(
          memberId: 'maria',
          coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
          updatedAt: now,
        ),
      ],
    );
    final device = FakeLocationDevice(
      permission: LocationAccess.granted,
      position: GeoCoordinate(latitude: 59.93, longitude: 30.31),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: DeviceLocationProvider(device: device),
          group: group,
        ),
      ),
    );
    await tester.pump();

    expect(device.requests, 0);
    final pin = _configuredPin(tester, 'Ваше местоположение');
    expect(pin.color, const Color(0xFF00897B));
    expect(_hasWhiteOutline(pin), isTrue);
    expect(
      _markerPoint(tester, 'Ваше местоположение'),
      const LatLng(59.93, 30.31),
    );
    expect(_semantics('Позиция участника: Мария'), findsOneWidget);
    expect(group.memberLocation(currentDemoUserId)!.coordinate, stored);
  });

  testWidgets('own position does not clear another member card', (
    tester,
  ) async {
    final now = DateTime.now();
    final gate = Completer<GeoCoordinate>();
    final device = FakeLocationDevice(
      permission: LocationAccess.granted,
      readGate: gate,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: DeviceLocationProvider(device: device),
          group: _locatedGroup(
            id: 'map-device-selection',
            now: now,
            members: [
              GroupMember(id: currentDemoUserId, name: 'Вы'),
              GroupMember(id: 'maria', name: 'Мария'),
            ],
            locations: [
              GroupMemberLocation(
                memberId: 'maria',
                coordinate: GeoCoordinate(
                  latitude: 55.7558,
                  longitude: 37.6173,
                ),
                updatedAt: now.subtract(const Duration(minutes: 4)),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();
    expect(find.text('Мария'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsOneWidget);

    gate.complete(GeoCoordinate(latitude: 55.7539, longitude: 37.6208));
    await tester.pump();
    await tester.pump();

    expect(device.requests, 0);
    expect(find.text('Мария'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsOneWidget);
    expect(
      _markerPoint(tester, 'Ваше местоположение'),
      const LatLng(55.7539, 37.6208),
    );
    expect(find.text('На карте: 2 участника'), findsNothing);
  });

  test('device camera moves only when nobody else is visible', () {
    expect(
      cameraUpdateForDevicePosition(otherParticipantVisible: false),
      DeviceCameraUpdate.moveToDevice,
    );
    expect(
      cameraUpdateForDevicePosition(otherParticipantVisible: true),
      DeviceCameraUpdate.keep,
    );
  });

  testWidgets('device position centers an otherwise empty map', (tester) async {
    final now = DateTime.now();
    const fresh = LatLng(59.93, 30.31);
    final device = FakeLocationDevice(
      permission: LocationAccess.granted,
      position: GeoCoordinate(
        latitude: fresh.latitude,
        longitude: fresh.longitude,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: DeviceLocationProvider(device: device),
          group: _locatedGroup(
            id: 'map-device-empty-camera',
            now: now,
            members: [GroupMember(id: currentDemoUserId, name: 'Вы')],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(device.requests, 0);
    expect(_markerPoint(tester, 'Ваше местоположение'), fresh);
    final camera = _camera(tester);
    expect(camera.center, fresh);
    expect(camera.zoom, 13);
  });

  testWidgets('device position keeps the camera when someone else is visible', (
    tester,
  ) async {
    final now = DateTime.now();
    const maria = LatLng(55.7558, 37.6173);
    final gate = Completer<GeoCoordinate>();
    final device = FakeLocationDevice(
      permission: LocationAccess.granted,
      readGate: gate,
      position: GeoCoordinate(latitude: 59.93, longitude: 30.31),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(
          locationProvider: DeviceLocationProvider(device: device),
          group: _locatedGroup(
            id: 'map-device-keep-camera',
            now: now,
            members: [
              GroupMember(id: currentDemoUserId, name: 'Вы'),
              GroupMember(id: 'maria', name: 'Мария'),
            ],
            locations: [
              GroupMemberLocation(
                memberId: 'maria',
                coordinate: GeoCoordinate(
                  latitude: maria.latitude,
                  longitude: maria.longitude,
                ),
                updatedAt: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final before = _camera(tester);

    gate.complete(GeoCoordinate(latitude: 59.93, longitude: 30.31));
    await tester.pump();
    await tester.pump();

    expect(device.requests, 0);
    expect(
      _markerPoint(tester, 'Ваше местоположение'),
      const LatLng(59.93, 30.31),
    );
    expect(_camera(tester).center, before.center);
    expect(_camera(tester).zoom, before.zoom);
    expect(_camera(tester).center, isNot(const LatLng(59.93, 30.31)));
  });

  testWidgets('a planned group does not build the map', (tester) async {
    final now = DateTime.now();
    final planned = group(
      id: 'map-planned',
      name: 'Позже',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(locationProvider: _silentLocation, group: planned),
      ),
    );
    await tester.pump();

    expect(
      find.text('Карта доступна только в активной группе.'),
      findsOneWidget,
    );
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('Тестовая точка на карте'), findsNothing);
  });
}

GeoGroup _twoActiveMembers(DateTime now) {
  return GeoGroup(
    id: 'map-tap',
    name: 'Прогулка',
    createdAt: now.subtract(const Duration(days: 1)),
    startsAt: now.subtract(const Duration(hours: 1)),
    endsAt: now.add(const Duration(hours: 2)),
    members: [
      GroupMember(id: 'maria', name: 'Мария'),
      GroupMember(id: 'alexey', name: 'Алексей'),
    ],
    memberLocations: [
      GroupMemberLocation(
        memberId: 'maria',
        coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
        updatedAt: now.subtract(const Duration(minutes: 5)),
      ),
      GroupMemberLocation(
        memberId: 'alexey',
        coordinate: GeoCoordinate(latitude: 55.749, longitude: 37.605),
        updatedAt: now.subtract(const Duration(minutes: 8)),
      ),
    ],
  );
}

Finder _positionLabel(String name) {
  return _semantics('Позиция участника: $name');
}

Finder _semantics(String label, {bool skipOffstage = true}) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
    skipOffstage: skipOffstage,
  );
}

Icon _pin(WidgetTester tester, String label) {
  return tester.widget<Icon>(
    find.descendant(
      of: _semantics(label),
      matching: find.byIcon(Icons.location_on),
    ),
  );
}

bool _hasWhiteOutline(Icon pin) {
  return pin.shadows?.any((shadow) => shadow.color == Colors.white) ?? false;
}

LatLng _markerPoint(WidgetTester tester, String label) {
  return _markerFor(tester, label).point;
}

MapCamera _camera(WidgetTester tester) {
  return MapController.of(tester.element(find.byType(MarkerLayer))).camera;
}

Icon _configuredPin(WidgetTester tester, String label) {
  final icon = _iconIn(_markerFor(tester, label).child);
  if (icon == null) {
    throw StateError('У маркера «$label» нет значка');
  }
  return icon;
}

Marker _markerFor(WidgetTester tester, String label) {
  final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
  for (final marker in layer.markers) {
    if (_semanticsLabel(marker.child) == label) {
      return marker;
    }
  }
  throw StateError('Маркер «$label» не найден');
}

Icon? _iconIn(Widget widget) {
  return switch (widget) {
    Icon() => widget,
    GestureDetector(:final child) when child != null => _iconIn(child),
    Tooltip(:final child) when child != null => _iconIn(child),
    Semantics(:final child) when child != null => _iconIn(child),
    Align(:final child) when child != null => _iconIn(child),
    Stack(:final children) =>
      children.map(_iconIn).whereType<Icon>().firstOrNull,
    _ => null,
  };
}

String? _semanticsLabel(Widget widget) {
  return switch (widget) {
    Semantics() => widget.properties.label,
    GestureDetector(:final child) when child != null => _semanticsLabel(child),
    Tooltip(:final child) when child != null => _semanticsLabel(child),
    _ => null,
  };
}

class _SilentLocation implements CurrentLocationProvider {
  const _SilentLocation();

  @override
  Future<LocationAccess> ensurePermissionForJoin() async {
    return LocationAccess.unavailable;
  }

  @override
  Future<GeoCoordinate?> currentPosition() async => null;
}

const _silentLocation = _SilentLocation();

GeoGroup _locatedGroup({
  required String id,
  required DateTime now,
  required List<GroupMember> members,
  List<GroupMemberLocation> locations = const [],
}) {
  return GeoGroup(
    id: id,
    name: 'Прогулка',
    createdAt: now.subtract(const Duration(days: 1)),
    startsAt: now.subtract(const Duration(hours: 1)),
    endsAt: now.add(const Duration(hours: 2)),
    members: members,
    memberLocations: locations,
  );
}

GeoGroup _samePoint({
  required String id,
  required DateTime now,
  required List<GroupMember> members,
}) {
  return GeoGroup(
    id: id,
    name: 'Одна точка',
    createdAt: now.subtract(const Duration(days: 1)),
    startsAt: now.subtract(const Duration(hours: 1)),
    endsAt: now.add(const Duration(hours: 2)),
    members: members,
    memberLocations: [
      for (final member in members)
        GroupMemberLocation(
          memberId: member.id,
          coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
          updatedAt: now,
        ),
    ],
  );
}

GeoGroup _organizerAndParticipant(DateTime now) {
  return GeoGroup(
    id: 'map-roles',
    name: 'Роли',
    createdAt: now.subtract(const Duration(days: 1)),
    startsAt: now.subtract(const Duration(hours: 1)),
    endsAt: now.add(const Duration(hours: 2)),
    members: [
      GroupMember(id: 'maria', name: 'Мария', role: MemberRole.organizer),
      GroupMember(id: 'alexey', name: 'Алексей'),
    ],
    memberLocations: [
      GroupMemberLocation(
        memberId: 'maria',
        coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
        updatedAt: now.subtract(const Duration(minutes: 3)),
      ),
      GroupMemberLocation(
        memberId: 'alexey',
        coordinate: GeoCoordinate(latitude: 55.749, longitude: 37.605),
        updatedAt: now.subtract(const Duration(minutes: 6)),
      ),
    ],
  );
}

GeoGroup _currentUserOrganizer(DateTime now) {
  return GeoGroup(
    id: 'map-self-organizer',
    name: 'Сам организатор',
    createdAt: now.subtract(const Duration(days: 1)),
    startsAt: now.subtract(const Duration(hours: 1)),
    endsAt: now.add(const Duration(hours: 2)),
    members: [
      GroupMember(
        id: currentDemoUserId,
        name: 'Вы',
        role: MemberRole.organizer,
      ),
      GroupMember(id: 'alexey', name: 'Алексей'),
    ],
    memberLocations: [
      GroupMemberLocation(
        memberId: currentDemoUserId,
        coordinate: GeoCoordinate(latitude: 55.7539, longitude: 37.6208),
        updatedAt: now.subtract(const Duration(minutes: 2)),
      ),
      GroupMemberLocation(
        memberId: 'alexey',
        coordinate: GeoCoordinate(latitude: 55.749, longitude: 37.605),
        updatedAt: now.subtract(const Duration(minutes: 6)),
      ),
    ],
  );
}
