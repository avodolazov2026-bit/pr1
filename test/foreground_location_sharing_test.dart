import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/location_repository.dart';
import 'package:geo_groups/location_sharing_coordinator.dart';
import 'package:geo_groups/location_sharing_service.dart';
import 'package:geo_groups/foreground_location_sharing.dart';

void main() {
  final start = DateTime.utc(2026, 11, 21, 10);

  test('resumed stream sends a valid sample to the coordinator', () async {
    final device = _Device();
    final sharing = _RecordingSharing();
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [_active(start)],
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    device.emit(_fix(start));
    await runtime.settle();

    expect(device.watches, 1);
    expect(device.requests, 0);
    expect(sharing.calls, hasLength(1));
    expect(sharing.calls.single.userId, 'user-1');
    expect(sharing.calls.single.sample.accuracyMeters, 5);
    expect(sharing.calls.single.sample.capturedAt, start);
    expect(sharing.calls.single.sample.coordinate.latitude, 55.75);
    expect(sharing.calls.single.sample.coordinate.longitude, 37.62);
  });

  test('paused and inactive cancel the stream', () async {
    final device = _Device();
    final sharing = _RecordingSharing();
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [_active(start)],
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
    device.emit(_fix(start));
    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    runtime.didChangeAppLifecycleState(AppLifecycleState.inactive);
    device.emit(_fix(start.add(const Duration(seconds: 5))));
    await runtime.settle();

    expect(device.watches, 2);
    expect(device.cancels, 2);
    expect(sharing.calls, isEmpty);
  });

  test('returning to resumed starts the stream again', () async {
    final device = _Device();
    final sharing = _RecordingSharing();
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [_active(start)],
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    device.emit(_fix(start));
    await runtime.settle();

    expect(device.watches, 2);
    expect(sharing.calls, hasLength(1));
  });

  test('no sharing target does not start a stream or ask permission', () async {
    final device = _Device(permission: LocationAccess.denied);
    final sharing = _RecordingSharing();
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [
        _group(
          id: 'later',
          at: start,
          startsAt: start.add(const Duration(hours: 1)),
        ),
      ],
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();

    expect(device.watches, 0);
    expect(device.checks, 0);
    expect(device.requests, 0);
    expect(sharing.calls, isEmpty);
  });

  test('an empty user does not start a stream or ask permission', () async {
    final device = _Device(permission: LocationAccess.denied);
    final sharing = _RecordingSharing();
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [_active(start)],
      userId: '',
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();

    expect(device.watches, 0);
    expect(device.requests, 0);
    expect(sharing.calls, isEmpty);
  });

  test('disabled service, denied and deniedForever stay quiet', () async {
    final disabled = _Device(servicesEnabled: false);
    final denied = _Device(
      permission: LocationAccess.denied,
      afterRequest: LocationAccess.denied,
    );
    final forever = _Device(permission: LocationAccess.deniedForever);
    final sharing = _RecordingSharing();

    for (final device in [disabled, denied, forever]) {
      final runtime = _runtime(
        device: device,
        sharing: sharing,
        groups: [_active(start)],
        now: start,
      );
      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await runtime.settle();
      expect(device.watches, 0);
    }

    expect(disabled.requests, 0);
    expect(denied.requests, 1);
    expect(forever.requests, 0);
    expect(sharing.calls, isEmpty);
  });

  testWidgets('a repeated check does not ask for permission again', (
    tester,
  ) async {
    final device = _Device(
      permission: LocationAccess.denied,
      afterRequest: LocationAccess.denied,
    );
    final sharing = _RecordingSharing();
    final moment = start;
    var elapsed = Duration.zero;
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [
        _active(moment, endsAt: moment.add(const Duration(minutes: 10))),
        _group(
          id: 'soon',
          at: moment,
          startsAt: moment.add(const Duration(minutes: 1)),
          endsAt: moment.add(const Duration(minutes: 10)),
        ),
      ],
      now: () => moment.add(elapsed),
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    elapsed = const Duration(minutes: 1);
    await tester.pump(const Duration(minutes: 1));

    expect(device.requests, 1);
    expect(device.watches, 0);
    expect(sharing.calls, isEmpty);
    runtime.dispose();
  });

  test('a group that is no longer shareable stops the stream', () async {
    final device = _Device();
    final sharing = _RecordingSharing();
    final groups = [
      _active(start, endsAt: start.add(const Duration(minutes: 5))),
    ];
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: groups,
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    device.emit(_fix(start));
    await runtime.settle();
    groups.single.endsAt = start.subtract(const Duration(minutes: 1));
    device.emit(_fix(start.add(const Duration(minutes: 2))));
    await runtime.settle();

    expect(sharing.calls, hasLength(1));
    expect(device.cancels, 1);
  });

  testWidgets('an ended group stops the stream without a new point', (
    tester,
  ) async {
    final device = _Device();
    final sharing = _RecordingSharing();
    final moment = start;
    var elapsed = Duration.zero;
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [_active(moment, endsAt: moment.add(const Duration(minutes: 2)))],
      now: () => moment.add(elapsed),
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(device.watches, 1);

    elapsed = const Duration(minutes: 2);
    await tester.pump(const Duration(minutes: 2));
    device.emit(_fix(moment.add(const Duration(minutes: 2))));
    await tester.pump();

    expect(device.cancels, 1);
    expect(sharing.calls, isEmpty);
    runtime.dispose();
  });

  test('invalid coordinates and accuracy are ignored', () async {
    final device = _Device();
    final sharing = _RecordingSharing();
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [_active(start)],
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    device.emit(_fix(start, latitude: 95));
    device.emit(_fix(start, longitude: double.nan));
    device.emit(_fix(start, accuracyMeters: -1));
    device.emit(_fix(start, accuracyMeters: double.infinity));
    await runtime.settle();

    expect(sharing.calls, isEmpty);
    expect(device.cancels, 0);
  });

  test(
    'dispose cancels the stream and a late permission cannot open it',
    () async {
      final device = _Device(permission: LocationAccess.denied);
      final gate = Completer<LocationAccess>();
      device.requestGate = gate;
      final sharing = _RecordingSharing();
      final runtime = _runtime(
        device: device,
        sharing: sharing,
        groups: [_active(start)],
        now: start,
      );

      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(device.requests, 1);

      runtime.dispose();
      gate.complete(LocationAccess.granted);
      await Future<void>.delayed(Duration.zero);
      device.emit(_fix(start));
      await runtime.settle();

      expect(device.watches, 0);
      expect(sharing.calls, isEmpty);
    },
  );

  test('a second point is skipped while the first is still sending', () async {
    final device = _Device();
    final gate = Completer<void>();
    final sharing = _RecordingSharing(gate: gate);
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [_active(start)],
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    device.emit(_fix(start));
    device.emit(_fix(start.add(const Duration(seconds: 1))));
    expect(sharing.calls, hasLength(1));

    gate.complete();
    await runtime.settle();

    expect(sharing.calls, hasLength(1));
  });

  testWidgets('start waits until lifecycle is actually resumed', (
    tester,
  ) async {
    final device = _Device(permission: LocationAccess.denied);
    final runtime = _runtime(
      device: device,
      sharing: _RecordingSharing(),
      groups: [_active(start)],
      now: start,
    );

    tester.binding.resetInternalState();
    runtime.start();
    await tester.pump();

    expect(tester.binding.lifecycleState, isNull);
    expect(device.checks, 0);
    expect(device.requests, 0);
    expect(device.watches, 0);

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();

    expect(device.requests, 1);
    runtime.dispose();
  });

  test('a resumed permission check finishes after pause and resume', () async {
    final device = _Device(permission: LocationAccess.denied);
    final gate = Completer<LocationAccess>();
    device.requestGate = gate;
    final runtime = _runtime(
      device: device,
      sharing: _RecordingSharing(),
      groups: [_active(start)],
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(device.requests, 1);
    expect(device.watches, 0);

    runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(device.watches, 0);
    expect(device.requests, 1);

    device.permission = LocationAccess.granted;
    gate.complete(LocationAccess.granted);
    await Future<void>.delayed(Duration.zero);
    await runtime.settle();

    expect(device.requests, 1);
    expect(device.watches, 1);
  });

  test('a late event from the old stream is ignored after resume', () async {
    final device = _Device();
    final sharing = _RecordingSharing();
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [_active(start)],
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();

    device.emitOn(0, _fix(start));
    await runtime.settle();
    device.emit(_fix(start.add(const Duration(seconds: 5))));
    await runtime.settle();

    expect(device.watches, 2);
    expect(sharing.calls, hasLength(1));
    expect(
      sharing.calls.single.sample.capturedAt,
      start.add(const Duration(seconds: 5)),
    );
  });

  test('a late error from the old stream does not stop the new one', () async {
    final device = _Device();
    final sharing = _RecordingSharing();
    final runtime = _runtime(
      device: device,
      sharing: sharing,
      groups: [_active(start)],
      now: start,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();
    runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await runtime.settle();

    device.failOn(0);
    device.emit(_fix(start));
    await runtime.settle();

    expect(device.watches, 2);
    expect(device.cancels, 1);
    expect(sharing.calls, hasLength(1));
  });
}

ForegroundLocationSharing _runtime({
  required _Device device,
  required _RecordingSharing sharing,
  required List<GeoGroup> groups,
  required Object now,
  String userId = 'user-1',
}) {
  return ForegroundLocationSharing(
    coordinator: LocationSharingCoordinator(
      sharing: sharing,
      readGroups: () => groups,
      readUserId: () => userId,
    ),
    device: device,
    now: now is DateTime Function() ? now : () => now as DateTime,
  );
}

LocationFix _fix(
  DateTime capturedAt, {
  double latitude = 55.75,
  double longitude = 37.62,
  double accuracyMeters = 5,
}) {
  return LocationFix(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    capturedAt: capturedAt,
  );
}

GeoGroup _active(DateTime at, {DateTime? endsAt}) {
  return _group(id: 'active', at: at, endsAt: endsAt);
}

GeoGroup _group({
  required String id,
  required DateTime at,
  DateTime? startsAt,
  DateTime? endsAt,
}) {
  return GeoGroup(
    id: id,
    name: 'Прогулка',
    createdAt: at.subtract(const Duration(days: 1)),
    startsAt: startsAt ?? at.subtract(const Duration(hours: 1)),
    endsAt: endsAt ?? at.add(const Duration(hours: 2)),
    members: [
      GroupMember(
        id: 'user-1',
        name: 'Участник',
        status: MembershipStatus.active,
      ),
    ],
  );
}

class _ShareCall {
  _ShareCall(this.userId, this.sample);

  final String userId;
  final LocationSample sample;
}

class _RecordingSharing extends LocationSharingService {
  _RecordingSharing({this.gate})
    : super(repository: const LocalLocationRepository());

  final Completer<void>? gate;
  final calls = <_ShareCall>[];

  @override
  Future<void> shareLocation({
    required String userId,
    required List<GeoGroup> groups,
    required LocationSample sample,
  }) async {
    calls.add(_ShareCall(userId, sample));
    final gate = this.gate;
    if (gate != null) {
      await gate.future;
    }
  }
}

class _Device implements LocationDevice {
  _Device({
    this.servicesEnabled = true,
    this.permission = LocationAccess.granted,
    this.afterRequest = LocationAccess.granted,
  });

  bool servicesEnabled;
  LocationAccess permission;
  LocationAccess afterRequest;
  Completer<LocationAccess>? requestGate;
  final streams = <_StickyFixStream>[];

  int checks = 0;
  int requests = 0;
  int watches = 0;
  int cancels = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => servicesEnabled;

  @override
  Future<LocationAccess> checkPermission() async {
    checks++;
    return permission;
  }

  @override
  Future<LocationAccess> requestPermission() {
    requests++;
    final gate = requestGate;
    if (gate != null) {
      return gate.future;
    }
    permission = afterRequest;
    return Future<LocationAccess>.value(afterRequest);
  }

  @override
  Future<GeoCoordinate> getCurrentPosition() {
    throw UnsupportedError('foreground runtime does not read a single fix');
  }

  @override
  Stream<LocationFix> watchPositions() {
    watches++;
    final stream = _StickyFixStream(() => cancels++);
    streams.add(stream);
    return stream;
  }

  void emit(LocationFix fix) {
    if (streams.isEmpty) {
      return;
    }
    emitOn(streams.length - 1, fix);
  }

  void emitOn(int index, LocationFix fix) => streams[index].emit(fix);

  void failOn(int index) => streams[index].fail(StateError('old'));
}

class _StickyFixStream extends Stream<LocationFix> {
  _StickyFixStream(this._onCancel);

  final void Function() _onCancel;
  void Function(LocationFix)? _onData;
  void Function(Object, StackTrace)? _onError;

  void emit(LocationFix fix) => _onData?.call(fix);

  void fail(Object error) => _onError?.call(error, StackTrace.empty);

  @override
  StreamSubscription<LocationFix> listen(
    void Function(LocationFix)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _onData = onData;
    _onError = switch (onError) {
      void Function(Object, StackTrace) both => both,
      void Function(Object) one => (Object error, StackTrace _) => one(error),
      _ => null,
    };
    return _StickySubscription(_onCancel);
  }
}

class _StickySubscription implements StreamSubscription<LocationFix> {
  _StickySubscription(this._onCancel);

  final void Function() _onCancel;

  @override
  Future<void> cancel() {
    _onCancel();
    return Future<void>.value();
  }

  @override
  void onData(void Function(LocationFix)? handleData) {}

  @override
  void onError(Function? handleError) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  bool get isPaused => false;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}
