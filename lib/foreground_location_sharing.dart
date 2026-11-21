import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/location_sharing_coordinator.dart';
import 'package:geo_groups/location_sharing_service.dart';

/// Держит GPS-поток только пока приложение на экране и есть куда передавать точку.
///
/// Свёрнутое и заблокированное приложение поток останавливает. Фоновый режим не включает.
class ForegroundLocationSharing extends WidgetsBindingObserver {
  ForegroundLocationSharing({
    required this.coordinator,
    LocationDevice? device,
    DateTime Function()? now,
  }) : _device = device ?? GeolocatorLocationDevice(),
       _now = now ?? DateTime.now;

  final LocationSharingCoordinator coordinator;
  final LocationDevice _device;
  final DateTime Function() _now;

  StreamSubscription<LocationFix>? _positions;
  Timer? _boundaryTimer;
  Future<void>? _evaluation;
  var _generation = 0;
  var _listenId = 0;
  var _resumed = false;
  var _observing = false;
  var _disposed = false;
  var _sharing = false;
  var _opening = false;
  var _requestedThisResume = false;

  /// Подписывается на жизненный цикл. Поток открывается только после resumed.
  void start() {
    if (_observing || _disposed) {
      return;
    }
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null) {
      return;
    }
    didChangeAppLifecycleState(state);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _resumed = true;
      _evaluation = _evaluate();
      return;
    }
    _resumed = false;
    _requestedThisResume = false;
    _generation++;
    _stopStream();
    _boundaryTimer?.cancel();
  }

  /// Завершает текущую проверку разрешений. Нужно тестам после смены состояния.
  Future<void> settle() => _evaluation ?? Future<void>.value();

  void dispose() {
    _disposed = true;
    _resumed = false;
    _generation++;
    _stopStream();
    _boundaryTimer?.cancel();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  Future<void> _evaluate() async {
    if (_disposed || !_resumed || _opening) {
      return;
    }
    final generation = _generation;
    if (!coordinator.hasSharingTarget(_now())) {
      _stopStream();
      _scheduleBoundary();
      return;
    }
    if (_positions != null) {
      _scheduleBoundary();
      return;
    }
    _opening = true;
    try {
      final enabled = await _device.isLocationServiceEnabled();
      if (!_canStart(generation) || !enabled) {
        _stopStream();
        _scheduleBoundary();
        return;
      }
      var access = await _device.checkPermission();
      if (!_canStart(generation)) {
        return;
      }
      if (access == LocationAccess.denied) {
        if (_requestedThisResume) {
          _stopStream();
          _scheduleBoundary();
          return;
        }
        _requestedThisResume = true;
        access = await _device.requestPermission();
        if (!_canStart(generation)) {
          return;
        }
      }
      if (access != LocationAccess.granted || !_canStart(generation)) {
        _stopStream();
        _scheduleBoundary();
        return;
      }
      final listenId = _listenId;
      _positions = _device.watchPositions().listen(
        (fix) {
          if (listenId != _listenId) {
            return;
          }
          _onFix(fix);
        },
        onError: (Object _, StackTrace _) {
          if (listenId != _listenId) {
            return;
          }
          _stopStream();
        },
      );
      _scheduleBoundary();
    } on MissingPluginException {
      _stopStream();
      _scheduleBoundary();
    } on PlatformException {
      _stopStream();
      _scheduleBoundary();
    } finally {
      _opening = false;
      if (!_disposed && _resumed && generation != _generation) {
        _evaluation = _evaluate();
      }
    }
  }

  void _onFix(LocationFix fix) {
    if (!_resumed || _disposed || _sharing || !_usable(fix)) {
      return;
    }
    final sample = LocationSample(
      coordinate: _coordinate(fix),
      accuracyMeters: fix.accuracyMeters,
      capturedAt: fix.capturedAt,
    );
    if (!coordinator.hasSharingTarget(sample.capturedAt)) {
      _stopStream();
      _scheduleBoundary();
      return;
    }
    _sharing = true;
    _evaluation = coordinator.shareSample(sample).whenComplete(() {
      _sharing = false;
      if (_disposed || !_resumed) {
        return;
      }
      if (!coordinator.hasSharingTarget(_now())) {
        _stopStream();
      }
      _scheduleBoundary();
    });
  }

  void _scheduleBoundary() {
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    if (_disposed || !_resumed) {
      return;
    }
    final moment = _now();
    final boundary = coordinator.nextSharingBoundary(moment);
    if (boundary == null) {
      return;
    }
    final delay = boundary.difference(moment);
    if (delay <= Duration.zero) {
      return;
    }
    _boundaryTimer = Timer(delay, () {
      if (_disposed || !_resumed) {
        return;
      }
      _evaluation = _evaluate();
    });
  }

  bool _canStart(int generation) {
    return !_disposed &&
        _resumed &&
        generation == _generation &&
        coordinator.hasSharingTarget(_now());
  }

  void _stopStream() {
    _listenId++;
    final current = _positions;
    _positions = null;
    current?.cancel();
  }
}

bool _usable(LocationFix fix) {
  return fix.latitude.isFinite &&
      fix.longitude.isFinite &&
      fix.accuracyMeters.isFinite &&
      fix.accuracyMeters >= 0 &&
      fix.latitude >= -90 &&
      fix.latitude <= 90 &&
      fix.longitude >= -180 &&
      fix.longitude <= 180;
}

/// Собирает координату только после проверки границ.
GeoCoordinate _coordinate(LocationFix fix) {
  return GeoCoordinate(latitude: fix.latitude, longitude: fix.longitude);
}
