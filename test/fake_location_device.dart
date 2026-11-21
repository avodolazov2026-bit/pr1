import 'dart:async';

import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_coordinate.dart';

class FakeLocationDevice implements LocationDevice {
  FakeLocationDevice({
    this.servicesEnabled = true,
    this.permission = LocationAccess.denied,
    this.afterRequest = LocationAccess.denied,
    this.position,
    this.serviceError,
    this.readError,
    this.readGate,
    this.permissionRequestGate,
  });

  bool servicesEnabled;
  LocationAccess permission;
  LocationAccess afterRequest;
  GeoCoordinate? position;
  Object? serviceError;
  Object? readError;
  Completer<GeoCoordinate>? readGate;
  Completer<LocationAccess>? permissionRequestGate;

  int checks = 0;
  int requests = 0;
  int reads = 0;

  @override
  Future<bool> isLocationServiceEnabled() async {
    if (serviceError != null) {
      throw serviceError!;
    }
    return servicesEnabled;
  }

  @override
  Future<LocationAccess> checkPermission() async {
    checks++;
    return permission;
  }

  @override
  Future<LocationAccess> requestPermission() async {
    requests++;
    final gate = permissionRequestGate;
    if (gate != null) {
      return gate.future;
    }
    permission = afterRequest;
    return afterRequest;
  }

  @override
  Future<GeoCoordinate> getCurrentPosition() async {
    reads++;
    final gate = readGate;
    if (gate != null) {
      return gate.future;
    }
    if (readError != null) {
      throw readError!;
    }
    final value = position;
    if (value == null) {
      throw StateError('Координата не задана');
    }
    return value;
  }

  @override
  Stream<LocationFix> watchPositions() => const Stream<LocationFix>.empty();
}
