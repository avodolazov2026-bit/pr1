import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_coordinate.dart';

import 'fake_location_device.dart';

void main() {
  final fresh = GeoCoordinate(latitude: 55.75, longitude: 37.62);

  test('already granted access does not request permission', () async {
    final device = FakeLocationDevice(
      permission: LocationAccess.granted,
      position: fresh,
    );
    final provider = DeviceLocationProvider(device: device);

    expect(await provider.ensurePermissionForJoin(), LocationAccess.granted);
    expect(await provider.currentPosition(), fresh);
    expect(device.requests, 0);
    expect(device.reads, 1);
  });

  test('denied access requests permission only while joining', () async {
    final device = FakeLocationDevice(
      permission: LocationAccess.denied,
      afterRequest: LocationAccess.denied,
    );
    final provider = DeviceLocationProvider(device: device);

    expect(await provider.currentPosition(), isNull);
    expect(device.requests, 0);

    expect(await provider.ensurePermissionForJoin(), LocationAccess.denied);
    expect(device.requests, 1);
  });

  test('denied forever does not request permission again', () async {
    final device = FakeLocationDevice(permission: LocationAccess.deniedForever);
    final provider = DeviceLocationProvider(device: device);

    expect(
      await provider.ensurePermissionForJoin(),
      LocationAccess.deniedForever,
    );
    expect(await provider.currentPosition(), isNull);
    expect(device.requests, 0);
  });

  test('disabled services and read errors stay safe', () async {
    final disabled = FakeLocationDevice(servicesEnabled: false);
    final disabledProvider = DeviceLocationProvider(device: disabled);

    expect(
      await disabledProvider.ensurePermissionForJoin(),
      LocationAccess.serviceDisabled,
    );
    expect(await disabledProvider.currentPosition(), isNull);
    expect(disabled.requests, 0);
    expect(disabled.checks, 0);

    final broken = FakeLocationDevice(
      permission: LocationAccess.granted,
      readError: StateError('gps'),
    );
    expect(
      await DeviceLocationProvider(device: broken).currentPosition(),
      isNull,
    );
    expect(broken.requests, 0);

    final exploded = FakeLocationDevice(serviceError: StateError('offline'));
    expect(
      await DeviceLocationProvider(device: exploded).ensurePermissionForJoin(),
      LocationAccess.unavailable,
    );
    expect(
      await DeviceLocationProvider(device: exploded).currentPosition(),
      isNull,
    );
  });
}
