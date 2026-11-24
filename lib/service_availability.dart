import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Доступность Qunora для всего приложения.
enum ServiceAvailability { checking, available, unavailable }

/// Сколько ждать ответ проверки, прежде чем считать сервис недоступным.
const serviceAvailabilityTimeout = Duration(seconds: 8);

typedef ServiceAvailabilityRpc = Future<Object?> Function();

/// Ошибка связи, а не отказ конкретной операции.
///
/// Ошибки приглашений, прав и проверки формы сюда не входят:
/// они не переводят всё приложение в недоступность.
bool isConnectivityFailure(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  const networkTypes = {
    'SocketException',
    'ClientException',
    'HandshakeException',
    'TlsException',
    'HttpException',
    'AuthRetryableFetchException',
  };
  if (networkTypes.contains(error.runtimeType.toString())) {
    return true;
  }
  if (error is AuthException) {
    final status = error.statusCode;
    return status == null || status.isEmpty || status == '0';
  }
  return false;
}

/// Единственный вызов, по которому решаем, жив ли сервис.
class SupabaseServiceAvailabilityCheck {
  const SupabaseServiceAvailabilityCheck({
    this._rpc,
    this.timeout = serviceAvailabilityTimeout,
  });

  final ServiceAvailabilityRpc? _rpc;
  final Duration timeout;

  Future<bool> check() async {
    try {
      final result = await (_rpc ?? _defaultRpc)().timeout(timeout);
      return result == true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'service availability failed: ${error.runtimeType}',
        );
      }
      return false;
    }
  }

  static Future<Object?> _defaultRpc() {
    return Supabase.instance.client.rpc('check_service_availability');
  }
}

/// Проверка при запуске и по кнопке «Повторить». Повторов по таймеру нет.
class ServiceAvailabilityController extends ChangeNotifier {
  ServiceAvailabilityController({required this._check});

  final Future<bool> Function() _check;

  ServiceAvailability status = ServiceAvailability.checking;
  var _generation = 0;
  var _started = false;
  var _sawUnavailable = false;
  var _disposed = false;

  /// Повторная проверка после уже показанного экрана недоступности.
  bool get retryInProgress =>
      status == ServiceAvailability.checking && _sawUnavailable;

  void ensureStarted() {
    if (_started) {
      return;
    }
    _started = true;
    _run();
  }

  Future<void> retry() {
    _started = true;
    return _run();
  }

  Future<void> _run() async {
    final generation = ++_generation;
    if (status != ServiceAvailability.checking) {
      status = ServiceAvailability.checking;
      _notify();
    }
    final Future<bool> pending;
    try {
      pending = _check();
    } catch (_) {
      if (_disposed || generation != _generation) {
        return;
      }
      _sawUnavailable = true;
      status = ServiceAvailability.unavailable;
      _notify();
      return;
    }
    final reachable = await pending.then<bool>(
      (value) => value,
      onError: (_) => false,
    );
    if (_disposed || generation != _generation) {
      return;
    }
    if (reachable) {
      status = ServiceAvailability.available;
    } else {
      _sawUnavailable = true;
      status = ServiceAvailability.unavailable;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
